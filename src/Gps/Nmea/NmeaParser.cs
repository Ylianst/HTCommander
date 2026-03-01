namespace GpsTool.Nmea;

/// <summary>
/// Validates and splits raw NMEA 0183 sentences.
/// </summary>
public static class NmeaParser
{
    /// <summary>
    /// Tries to parse a raw NMEA line into its sentence identifier and data fields.
    /// Returns false when the line is malformed or the checksum is invalid.
    /// </summary>
    public static bool TryParse(string line, out string sentenceId, out string[] fields)
    {
        sentenceId = string.Empty;
        fields = [];

        if (string.IsNullOrWhiteSpace(line))
            return false;

        line = line.Trim();

        // Must start with '$' or '!'
        if (line.Length < 6 || (line[0] != '$' && line[0] != '!'))
            return false;

        // Split off the checksum (after '*')
        int starIndex = line.LastIndexOf('*');
        string body;
        if (starIndex > 0 && starIndex < line.Length - 1)
        {
            string checksumHex = line[(starIndex + 1)..];
            body = line[1..starIndex]; // skip leading '$'

            if (!ValidateChecksum(body, checksumHex))
                return false;
        }
        else
        {
            // No checksum – accept but log a warning
            body = line[1..];
        }

        var parts = body.Split(',');
        if (parts.Length == 0)
            return false;

        sentenceId = parts[0]; // e.g. "GPGGA", "GNGGA"
        fields = parts;
        return true;
    }

    /// <summary>
    /// Computes XOR checksum over the body (between '$' and '*') and compares it
    /// with the provided two-character hex value.
    /// </summary>
    private static bool ValidateChecksum(string body, string expectedHex)
    {
        if (expectedHex.Length < 2)
            return false;

        byte computed = 0;
        foreach (char c in body)
            computed ^= (byte)c;

        return int.TryParse(expectedHex, System.Globalization.NumberStyles.HexNumber, null, out int expected)
            && computed == expected;
    }
}
