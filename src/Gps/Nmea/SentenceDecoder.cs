using GpsTool.Nmea.Sentences;

namespace GpsTool.Nmea;

/// <summary>
/// Routes a parsed NMEA sentence to the appropriate decoder and returns a
/// human-readable representation, or null for unsupported sentences.
/// </summary>
public static class SentenceDecoder
{
    /// <summary>
    /// Decodes a raw NMEA line and returns a formatted string, or null if the
    /// sentence type is not supported.
    /// </summary>
    public static string? Decode(string rawLine)
    {
        if (!NmeaParser.TryParse(rawLine, out string sentenceId, out string[] fields))
            return null;

        // The talker ID is the first two characters (e.g. "GP", "GN", "GL").
        // The sentence type is the remaining characters.
        string type = sentenceId.Length >= 5 ? sentenceId[2..] : sentenceId;

        try
        {
            return type switch
            {
                "GGA" => GgaSentence.Parse(fields).ToString(),
                "RMC" => RmcSentence.Parse(fields).ToString(),
                "GSA" => GsaSentence.Parse(fields).ToString(),
                "GSV" => GsvSentence.Parse(fields).ToString(),
                "VTG" => VtgSentence.Parse(fields).ToString(),
                "GLL" => GllSentence.Parse(fields).ToString(),
                "ZDA" => ZdaSentence.Parse(fields).ToString(),
                _ => null
            };
        }
        catch
        {
            return null;
        }
    }
}
