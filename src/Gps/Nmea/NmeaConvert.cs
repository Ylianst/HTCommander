using System;
using System.Globalization;

namespace GpsTool.Nmea;

/// <summary>
/// Helper methods shared across NMEA sentence decoders.
/// </summary>
internal static class NmeaConvert
{
    /// <summary>
    /// Converts a NMEA latitude/longitude value (e.g. "4807.038") and a
    /// hemisphere indicator ('N','S','E','W') to decimal degrees.
    /// </summary>
    public static double? ToDecimalDegrees(string value, string hemisphere)
    {
        if (string.IsNullOrEmpty(value) || string.IsNullOrEmpty(hemisphere))
            return null;

        if (!double.TryParse(value, System.Globalization.CultureInfo.InvariantCulture, out double raw))
            return null;

        // NMEA format: DDDMM.MMMMM  (degrees * 100 + minutes)
        int degrees = (int)(raw / 100);
        double minutes = raw - degrees * 100;
        double dec = degrees + minutes / 60.0;

        if (hemisphere is "S" or "W")
            dec = -dec;

        return dec;
    }

    /// <summary>
    /// Parses a NMEA UTC time field (HHMMSS.sss) into a TimeSpan.
    /// </summary>
    public static TimeSpan? ToUtcTime(string value)
    {
        if (string.IsNullOrEmpty(value) || value.Length < 6)
            return null;

        if (!int.TryParse(value[..2], out int h) ||
            !int.TryParse(value[2..4], out int m) ||
            !double.TryParse(value[4..], System.Globalization.CultureInfo.InvariantCulture, out double s))
            return null;

        return new TimeSpan(0, h, m, (int)s, (int)((s - (int)s) * 1000));
    }

    /// <summary>
    /// Parses a NMEA date field (DDMMYY) into a DateOnly.
    /// </summary>
    public static DateOnly? ToDate(string value)
    {
        if (string.IsNullOrEmpty(value) || value.Length < 6)
            return null;

        if (!int.TryParse(value[..2], out int day) ||
            !int.TryParse(value[2..4], out int month) ||
            !int.TryParse(value[4..6], out int year))
            return null;

        year += year < 80 ? 2000 : 1900;

        try { return new DateOnly(year, month, day); }
        catch { return null; }
    }

    public static double? ToDouble(string value)
    {
        if (string.IsNullOrEmpty(value))
            return null;
        return double.TryParse(value, System.Globalization.CultureInfo.InvariantCulture, out double v) ? v : null;
    }

    public static int? ToInt(string value)
    {
        if (string.IsNullOrEmpty(value))
            return null;
        return int.TryParse(value, out int v) ? v : null;
    }
}
